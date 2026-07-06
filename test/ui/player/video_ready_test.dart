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
import 'package:kivo_player/ui/player/state/video_ready_state.dart';
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

void main() {
  testWidgets('fresh open seeds videoFrameReady false until the first frame arrives', (tester) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = _container(engine, s);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(
      const VideoSession(playbackPath: '/v/ep1.mkv', displayName: 'ep1.mkv', queue: ['/v/ep1.mkv'], index: 0),
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: PlayerScreen()),
    ));
    await tester.pump(); // let the post-frame _start / _openSession run

    // Fresh open: no decoded frame yet → cover is armed.
    expect(c.read(videoFrameReadyProvider), false);

    // media_kit reports the first decoded frame of the new media.
    engine.emitVideoFrame(true);
    await tester.pump();
    expect(c.read(videoFrameReadyProvider), true);

    // A subsequent open resets width→null (stale-frame window) → cover re-arms.
    engine.emitVideoFrame(false);
    await tester.pump();
    expect(c.read(videoFrameReadyProvider), false);

    await tester.pump(const Duration(seconds: 4)); // drain timers
  });
}
