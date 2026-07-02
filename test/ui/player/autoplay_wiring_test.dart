import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/device_controls_provider.dart';
import 'package:kivo_player/platform/frame_extractor_provider.dart';
import 'package:kivo_player/platform/interfaces/device_controls.dart';
import 'package:kivo_player/platform/pip_controller_provider.dart';
import 'package:kivo_player/platform/subtitle_finder_provider.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/loop/ab_loop.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/ui/player/player_screen.dart';
import 'package:kivo_player/ui/player/state/autoplay_state.dart';
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
  const session = VideoSession(
    playbackPath: '/v/ep1.mkv',
    displayName: 'ep1.mkv',
    queue: ['/v/ep1.mkv', '/v/ep2.mkv'],
    queueNames: ['ep1.mkv', 'ep2.mkv'],
    index: 0,
    folder: '/v',
  );

  Future<ProviderContainer> pumpPlayer(
    WidgetTester tester, {
    required FakePlaybackEngine engine,
    bool autoplayNext = true,
  }) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    if (!autoplayNext) {
      await s.update(s.current.copyWith(autoplayNext: false));
    }
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
      deviceControlsProvider.overrideWithValue(NoopControls()),
      resumeServiceProvider.overrideWithValue(ResumeService(InMemoryResumeStore())),
      playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
      frameExtractorProvider.overrideWithValue(FakeFrameExtractor()),
      subtitleFinderProvider.overrideWithValue(FakeSubtitleFinder()),
      pipControllerProvider.overrideWithValue(FakePipController()),
    ]);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(session);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: PlayerScreen()),
    ));
    await tester.pump();
    // Drain _applyDefaultTracks so it doesn't touch a torn-down engine later.
    engine.emitAudioTracks(const []);
    await tester.pump();
    engine.emitSubtitleTracks(const []);
    await tester.pump();
    await tester.pump();

    return c;
  }

  testWidgets('foreground completion with a next video sets autoplayPendingProvider',
      (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final c = await pumpPlayer(tester, engine: engine);

    expect(c.read(autoplayPendingProvider), isNull);
    engine.emitCompleted(true);
    await tester.pump();

    final pending = c.read(autoplayPendingProvider);
    expect(pending, isNotNull);
    expect(pending!.playbackPath, '/v/ep2.mkv');
    expect(pending.index, 1);

    // This test only asserts the pending-set behavior, not the overlay's own
    // 3s countdown → advance flow (covered by autoplay_overlay_test.dart and
    // the confirm-listener wiring below). Clear it before the drain pump so
    // the AutoplayOverlay's ring doesn't fire mid-drain and kick off a second
    // engine.open() cycle whose fresh track-stream timeouts would outlive
    // this test.
    c.read(autoplayPendingProvider.notifier).state = null;
    await tester.pump(const Duration(seconds: 4)); // drain periodic save timer
  });

  testWidgets('autoplayNext=false leaves pending null on completion', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final c = await pumpPlayer(tester, engine: engine, autoplayNext: false);

    engine.emitCompleted(true);
    await tester.pump();

    expect(c.read(autoplayPendingProvider), isNull);

    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('an active A-B loop suppresses autoplay on completion', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final c = await pumpPlayer(tester, engine: engine);

    c.read(abLoopProvider.notifier).begin();
    c.read(abLoopProvider.notifier).mark(); // armedB
    engine.emitPosition(const Duration(seconds: 5));
    await tester.pump();
    c.read(abLoopProvider.notifier).mark(); // active (a=0, b=5)
    expect(c.read(abLoopProvider)?.phase, AbLoopPhase.active);

    engine.emitCompleted(true);
    await tester.pump();

    expect(c.read(autoplayPendingProvider), isNull);

    await tester.pump(const Duration(seconds: 4));
  });
}
