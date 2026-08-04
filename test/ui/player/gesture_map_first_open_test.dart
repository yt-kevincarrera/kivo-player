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
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/ui/player/player_screen.dart';
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

ProviderContainer _container(FakePlaybackEngine engine, SettingsService s) =>
    ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
      deviceControlsProvider.overrideWithValue(NoopControls()),
      resumeServiceProvider.overrideWithValue(ResumeService(InMemoryResumeStore())),
      playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
      frameExtractorProvider.overrideWithValue(FakeFrameExtractor()),
      subtitleFinderProvider.overrideWithValue(FakeSubtitleFinder()),
      pipControllerProvider.overrideWithValue(FakePipController()),
    ]);

const _session = VideoSession(
    playbackPath: '/v/ep1.mkv',
    displayName: 'ep1.mkv',
    queue: ['/v/ep1.mkv'],
    index: 0);

/// The fake engine returns no video controller, so PlayerScreen keeps a
/// CircularProgressIndicator spinning — pumpAndSettle would never converge.
/// Pump fixed slices instead, long enough for the route/page animations.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Drains applyDefaultTracks' two SEQUENTIAL 2s stream timeouts (the fake
/// engine never emits track lists), then unmounts while the container and the
/// engine are still alive — PlayerScreen.dispose() must not write to a disposed
/// provider, and a pending `.first` must not outlive the engine's streams.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void main() {
  testWidgets('the first ever open pauses and shows the gesture map, then resumes',
      (tester) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = _container(engine, s);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(_session);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: PlayerScreen()),
    ));
    await _settle(tester);

    expect(find.text('TOQUES'), findsOneWidget);
    expect(engine.lastPlayingCommand, false); // paused for the tutorial

    await tester.tap(find.text('Siguiente'));
    await _settle(tester);
    await tester.tap(find.text('Siguiente'));
    await _settle(tester);
    await tester.tap(find.text('Entendido'));
    await _settle(tester);

    expect(find.text('BOTONES'), findsNothing);
    expect(engine.lastPlayingCommand, true); // resumed
    expect(c.read(settingsProvider).gestureMapShown, true); // persisted on close

    await _unmount(tester);
  });

  testWidgets('a later open does not show the map', (tester) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final s = await SettingsService.load(InMemorySettingsStore());
    await s.update(s.current.copyWith(gestureMapShown: true));
    final c = _container(engine, s);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(_session);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: PlayerScreen()),
    ));
    await _settle(tester);

    expect(find.text('TOQUES'), findsNothing);

    await _unmount(tester);
  });
}
