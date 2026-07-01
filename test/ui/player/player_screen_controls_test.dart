import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/device_controls_provider.dart';
import 'package:kivo_player/platform/frame_extractor_provider.dart';
import 'package:kivo_player/platform/interfaces/device_controls.dart';
import 'package:kivo_player/platform/subtitle_finder_provider.dart';
import 'package:kivo_player/player/engine/playback_engine.dart' show MediaTrack;
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/ui/player/player_screen.dart';
import 'package:kivo_player/ui/player/state/controls_visibility.dart';
import 'package:kivo_player/ui/player/state/mini_player_state.dart';
import 'package:kivo_player/ui/player/controls/center_controls.dart';
import '../../fakes/fakes.dart';

class NoopControls implements DeviceControls {
  @override Future<double> currentBrightness() async => 0.5;
  @override Future<void> setBrightness(double v) async {}
  @override Future<double> currentVolume() async => 0.5;
  @override Future<void> setSystemVolume(double v) async {}
  @override Future<void> setOrientation(List<DeviceOrientationLock> o) async {}
  @override Future<void> keepAwake(bool on) async {}
  @override Future<void> setImmersive(bool on) async {}
  @override Future<void> resetBrightness() async {}
  @override Stream<double> get systemVolumeStream => const Stream<double>.empty();
  @override Future<void> setVolumeKeyInterception(bool on) async {}
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
      playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
      frameExtractorProvider.overrideWithValue(FakeFrameExtractor()),
      subtitleFinderProvider.overrideWithValue(FakeSubtitleFinder()),
    ]);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(
      const VideoSession(playbackPath: '/v/ep1.mkv', displayName: 'ep1.mkv', queue: ['/v/ep1.mkv'], index: 0),
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: PlayerScreen()),
    ));
    await tester.pump();

    expect(c.read(controlsVisibleProvider), false);
    await tester.tapAt(tester.getCenter(find.byType(PlayerScreen)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(c.read(controlsVisibleProvider), true);
    expect(find.byType(CenterControls), findsOneWidget);
    // Drain the auto-hide timer so no pending timers remain at teardown.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('popping the player saves progress before the route is removed', (tester) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final s = await SettingsService.load(InMemorySettingsStore());
    final resumeStore = InMemoryResumeStore();
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
      deviceControlsProvider.overrideWithValue(NoopControls()),
      resumeServiceProvider.overrideWithValue(ResumeService(resumeStore)),
      playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
      frameExtractorProvider.overrideWithValue(FakeFrameExtractor()),
      subtitleFinderProvider.overrideWithValue(FakeSubtitleFinder()),
    ]);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(
      const VideoSession(playbackPath: '/v/ep1.mkv', displayName: 'ep1.mkv', queue: ['/v/ep1.mkv'], index: 0),
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PlayerScreen()),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find.text('open'));
    // Drive the push transition without pumpAndSettle: PlayerScreen's
    // periodic 4s save timer keeps scheduling frames forever, which would
    // make pumpAndSettle time out.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // finish the route transition

    expect(find.byType(PlayerScreen), findsOneWidget);

    // Simulate real playback progress flowing through the position/duration
    // providers, the same wiring PlayerScreen's build() listens to via
    // ref.listen to keep _lastPosition/_lastDuration current.
    engine.emitDuration(const Duration(minutes: 10));
    engine.emitPosition(const Duration(minutes: 2));
    await tester.pump();

    // Nothing persisted yet — no pop, no periodic timer fired.
    expect(resumeStore.entries(), isEmpty);

    // Pop via the navigator, exactly like the top-bar back button, the
    // system back gesture, and the swipe-down dismiss all do (they all
    // funnel through Navigator.maybePop()).
    final playerElement = tester.element(find.byType(PlayerScreen));
    Navigator.of(playerElement).maybePop();
    // PopScope's onPopInvokedWithResult awaits _saveProgress() before the
    // actual pop happens; pump to let that microtask/await chain complete,
    // then pump the pop's exit transition to completion.
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // The player route is gone...
    expect(find.byType(PlayerScreen), findsNothing);
    // ...and the resume store already reflects the latest position, proving
    // the save happened as part of the pop rather than racing behind it.
    final saved = resumeStore.entries();
    expect(saved, hasLength(1));
    expect(saved.single.key, 'ep1.mkv');
    expect(saved.single.seconds, const Duration(minutes: 2).inSeconds);

    // Drain the periodic save timer so no pending timers remain at teardown.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('popping the player minimizes it and captures a preview frame',
      (tester) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final s = await SettingsService.load(InMemorySettingsStore());
    final resumeStore = InMemoryResumeStore();
    final frames = FakeFrameExtractor();
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
      deviceControlsProvider.overrideWithValue(NoopControls()),
      resumeServiceProvider.overrideWithValue(ResumeService(resumeStore)),
      playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
      frameExtractorProvider.overrideWithValue(frames),
      subtitleFinderProvider.overrideWithValue(FakeSubtitleFinder()),
    ]);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(
      const VideoSession(playbackPath: '/v/ep1.mkv', displayName: 'ep1.mkv', queue: ['/v/ep1.mkv'], index: 0),
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PlayerScreen()),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(c.read(playerMinimizedProvider), false);

    engine.emitDuration(const Duration(minutes: 10));
    engine.emitPosition(const Duration(minutes: 3));
    await tester.pump();

    final playerElement = tester.element(find.byType(PlayerScreen));
    Navigator.of(playerElement).maybePop();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(PlayerScreen), findsNothing);
    expect(c.read(playerMinimizedProvider), true);
    expect(c.read(miniPlayerThumbnailProvider), isNotNull);
    expect(frames.requested, contains(const Duration(minutes: 3)));

    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('opening a video resets minimized state and the preview',
      (tester) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
      deviceControlsProvider.overrideWithValue(NoopControls()),
      resumeServiceProvider.overrideWithValue(ResumeService(InMemoryResumeStore())),
      playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
      frameExtractorProvider.overrideWithValue(FakeFrameExtractor()),
      subtitleFinderProvider.overrideWithValue(FakeSubtitleFinder()),
    ]);
    addTearDown(c.dispose);
    // Simulate leftover state from a previously minimized video.
    c.read(playerMinimizedProvider.notifier).state = true;
    c.read(miniPlayerThumbnailProvider.notifier).state = Uint8List.fromList([1, 2, 3]);
    c.read(currentVideoProvider.notifier).open(
      const VideoSession(playbackPath: '/v/ep2.mkv', displayName: 'ep2.mkv', queue: ['/v/ep2.mkv'], index: 0),
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: PlayerScreen()),
    ));
    await tester.pump();

    expect(c.read(playerMinimizedProvider), false);
    expect(c.read(miniPlayerThumbnailProvider), isNull);

    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets(
      'expanding the same minimized session reconnects without reopening the file',
      (tester) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
      deviceControlsProvider.overrideWithValue(NoopControls()),
      resumeServiceProvider.overrideWithValue(ResumeService(InMemoryResumeStore())),
      playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
      frameExtractorProvider.overrideWithValue(FakeFrameExtractor()),
      subtitleFinderProvider.overrideWithValue(FakeSubtitleFinder()),
    ]);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(
      const VideoSession(playbackPath: '/v/ep1.mkv', displayName: 'ep1.mkv', queue: ['/v/ep1.mkv'], index: 0),
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PlayerScreen()),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(engine.openCount, 1);

    engine.emitDuration(const Duration(minutes: 10));
    engine.emitPosition(const Duration(minutes: 2));
    await tester.pump();

    // Minimize (simulating a pop from any exit path).
    final playerElement = tester.element(find.byType(PlayerScreen));
    Navigator.of(playerElement).maybePop();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(PlayerScreen), findsNothing);
    expect(c.read(playerMinimizedProvider), true);

    // Simulate playback advancing further while minimized (e.g. the
    // mini-bar's own play button resumed it) — nothing persists this
    // to the resume store since no PlayerScreen instance is listening.
    engine.emitPosition(const Duration(minutes: 5));
    await tester.pump();

    // Expand: re-push PlayerScreen for the SAME session (mirrors what
    // MiniPlayerBar._expand does when tapped).
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(PlayerScreen), findsOneWidget);

    // Must NOT reopen the file — that would reseek to the stale resume-store
    // position (2 min) instead of leaving the engine at its live position
    // (5 min, from the emitPosition above).
    expect(engine.openCount, 1);
    expect(c.read(playerMinimizedProvider), false);

    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('opening a video auto-selects the preferred subtitle language',
      (tester) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final s = await SettingsService.load(InMemorySettingsStore());
    await s.update(s.current.copyWith(preferredSubtitleLanguage: 'es'));
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
      deviceControlsProvider.overrideWithValue(NoopControls()),
      resumeServiceProvider.overrideWithValue(ResumeService(InMemoryResumeStore())),
      playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
      frameExtractorProvider.overrideWithValue(FakeFrameExtractor()),
      subtitleFinderProvider.overrideWithValue(FakeSubtitleFinder()),
    ]);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(
      const VideoSession(playbackPath: '/v/ep1.mkv', displayName: 'ep1.mkv', queue: ['/v/ep1.mkv'], index: 0),
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: PlayerScreen()),
    ));
    await tester.pump();

    // _applyDefaultTracks awaits the audio-tracks stream first (both streams
    // are broadcast, so an emission is dropped unless a listener is already
    // subscribed). Emit audio tracks and pump so the audio stage resolves and
    // _applyDefaultTracks moves on to subscribe to subtitleTracksStream,
    // THEN emit the subtitle tracks it's actually waiting on.
    engine.emitAudioTracks(const []);
    await tester.pump();
    engine.emitSubtitleTracks(const [
      MediaTrack(id: 'sub-en', language: 'en'),
      MediaTrack(id: 'sub-es', language: 'es'),
    ]);
    await tester.pump();
    // Drain the async _applyDefaultTracks chain (the .first future resolves
    // on the next microtask/pump after the stream emits).
    await tester.pump();

    expect(engine.currentSubtitleTrackId, 'sub-es');

    await tester.pump(const Duration(seconds: 4)); // drain the periodic save timer
  });
}
