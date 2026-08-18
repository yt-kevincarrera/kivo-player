import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
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
import 'package:kivo_player/ui/mini_player/mini_player_bar.dart';
import 'package:kivo_player/ui/player/player_screen.dart';
import 'package:kivo_player/ui/player/state/mini_player_state.dart';
import '../../fakes/fakes.dart';

class _NoopControls implements DeviceControls {
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

/// Pumps the mini-bar over a minimized, PLAYING session — the state that only
/// becomes reachable once minimizing stops force-pausing.
Future<({ProviderContainer container, FakePlaybackEngine engine})> _pumpMinimizedBar(
  WidgetTester tester, {
  KivoSettings? settings,
}) async {
  final engine = FakePlaybackEngine();
  addTearDown(engine.dispose);
  final s = await SettingsService.load(InMemorySettingsStore());
  if (settings != null) await s.update(settings);
  final c = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(s),
    playbackEngineProvider.overrideWithValue(engine),
    deviceControlsProvider.overrideWithValue(_NoopControls()),
    resumeServiceProvider.overrideWithValue(ResumeService(InMemoryResumeStore())),
    playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
    frameExtractorProvider.overrideWithValue(FakeFrameExtractor()),
    subtitleFinderProvider.overrideWithValue(FakeSubtitleFinder()),
    pipControllerProvider.overrideWithValue(FakePipController()),
  ]);
  addTearDown(c.dispose);
  c.read(currentVideoProvider.notifier).open(
        const VideoSession(
            playbackPath: '/v/ep1.mkv',
            displayName: 'ep1.mkv',
            queue: ['/v/ep1.mkv'],
            index: 0),
      );
  c.read(playerMinimizedProvider.notifier).state = true;
  await engine.play();

  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: const MaterialApp(home: Scaffold(body: MiniPlayerBar())),
  ));
  await tester.pumpAndSettle();
  return (container: c, engine: engine);
}

/// Pumps the real player, plays, then pops it — the same path the swipe-down,
/// the top-bar arrow and the system back all funnel through — and reports what
/// the engine was last told to do.
Future<bool?> _minimizeRealPlayer(WidgetTester tester,
    {required bool keepPlaying}) async {
  final engine = FakePlaybackEngine();
  addTearDown(engine.dispose);
  final s = await SettingsService.load(InMemorySettingsStore());
  // gestureMapShown: the first-run gesture map is a full-screen route that
  // would swallow the maybePop() below instead of the player.
  await s.update(KivoSettings.defaults()
      .copyWith(minimizeKeepsPlaying: keepPlaying, gestureMapShown: true));
  final c = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(s),
    playbackEngineProvider.overrideWithValue(engine),
    deviceControlsProvider.overrideWithValue(_NoopControls()),
    resumeServiceProvider.overrideWithValue(ResumeService(InMemoryResumeStore())),
    playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
    frameExtractorProvider.overrideWithValue(FakeFrameExtractor()),
    subtitleFinderProvider.overrideWithValue(FakeSubtitleFinder()),
    pipControllerProvider.overrideWithValue(FakePipController()),
  ]);
  addTearDown(c.dispose);
  c.read(currentVideoProvider.notifier).open(
        const VideoSession(
            playbackPath: '/v/ep1.mkv',
            displayName: 'ep1.mkv',
            queue: ['/v/ep1.mkv'],
            index: 0),
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
  // No pumpAndSettle: PlayerScreen's periodic 4s save timer schedules frames
  // forever, so settle would time out.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));

  engine.emitDuration(const Duration(minutes: 10));
  engine.emitPosition(const Duration(minutes: 2));
  await engine.play();
  await tester.pump();
  expect(engine.lastPlayingCommand, true, reason: 'precondition: playing');

  Navigator.of(tester.element(find.byType(PlayerScreen))).maybePop();
  // complete() plays a 240ms shrink BEFORE Navigator.pop(), which then runs its
  // own ~300ms exit transition; cover both stages sequentially.
  await tester.pump();
  await tester.pump();
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
  expect(find.byType(PlayerScreen), findsNothing);

  final last = engine.lastPlayingCommand;
  await tester.pump(const Duration(seconds: 4)); // drain the save timer
  return last;
}

void main() {
  testWidgets('minimizing pauses when the setting is off', (tester) async {
    expect(await _minimizeRealPlayer(tester, keepPlaying: false), false);
  });

  testWidgets('minimizing keeps playing when the setting is on', (tester) async {
    expect(await _minimizeRealPlayer(tester, keepPlaying: true), true,
        reason: 'neither _completeDismiss nor dispose() may pause here');
  });

  testWidgets('the close button pauses the engine', (tester) async {
    final h = await _pumpMinimizedBar(tester);
    expect(h.engine.lastPlayingCommand, true);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(h.engine.lastPlayingCommand, false,
        reason: 'the mini-bar can no longer assume playback was already paused');
    expect(h.container.read(playerMinimizedProvider), false);
  });

  testWidgets('swiping the bar away pauses the engine', (tester) async {
    final h = await _pumpMinimizedBar(tester);

    await tester.drag(find.byType(MiniPlayerBar), const Offset(500, 0));
    await tester.pumpAndSettle();

    expect(h.engine.lastPlayingCommand, false);
    expect(h.container.read(playerMinimizedProvider), false);
  });

  testWidgets('closing pauses regardless of minimizeKeepsPlaying', (tester) async {
    // The setting governs the minimize TRANSITION, not the close: dismissing the
    // mini-bar is "I'm done with this video" either way.
    final h = await _pumpMinimizedBar(tester,
        settings: KivoSettings.defaults().copyWith(minimizeKeepsPlaying: true));

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(h.engine.lastPlayingCommand, false);
  });
}
