import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/device_controls_provider.dart';
import 'package:kivo_player/platform/frame_extractor_provider.dart';
import 'package:kivo_player/platform/interfaces/device_controls.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/ui/mini_player/mini_player_bar.dart';
import 'package:kivo_player/ui/player/player_screen.dart';
import 'package:kivo_player/ui/player/state/mini_player_state.dart';
import '../../fakes/fakes.dart';

// A local no-op DeviceControls fake — deliberately not imported from
// player_screen_controls_test.dart to avoid coupling one test file's
// internals to another's.
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

Future<ProviderContainer> _pumpBar(WidgetTester tester, {required bool minimized}) async {
  final engine = FakePlaybackEngine();
  addTearDown(engine.dispose);
  final s = await SettingsService.load(InMemorySettingsStore());
  final c = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(s),
    playbackEngineProvider.overrideWithValue(engine),
    deviceControlsProvider.overrideWithValue(_NoopControls()),
    resumeServiceProvider.overrideWithValue(ResumeService(InMemoryResumeStore())),
    playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
    frameExtractorProvider.overrideWithValue(FakeFrameExtractor()),
  ]);
  addTearDown(c.dispose);
  c.read(currentVideoProvider.notifier).open(
    const VideoSession(playbackPath: '/v/ep1.mkv', displayName: 'ep1.mkv', queue: ['/v/ep1.mkv'], index: 0),
  );
  c.read(playerMinimizedProvider.notifier).state = minimized;

  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: const MaterialApp(home: Scaffold(body: MiniPlayerBar())),
  ));
  await tester.pump();
  return c;
}

void main() {
  testWidgets('shows the title when minimized', (tester) async {
    await _pumpBar(tester, minimized: true);
    expect(find.text('ep1.mkv'), findsOneWidget);
  });

  testWidgets('is not hit-testable when not minimized', (tester) async {
    await _pumpBar(tester, minimized: false);
    // The close button exists in the tree (always mounted for the implicit
    // animation) but must not be tappable while hidden. Scope the finder to
    // the IgnorePointer inside MiniPlayerBar itself: Scaffold/FocusTraversal
    // machinery also inserts IgnorePointer ancestors elsewhere in the tree.
    final ignorePointer = tester.widget<IgnorePointer>(
      find.descendant(
        of: find.byType(MiniPlayerBar),
        matching: find.byType(IgnorePointer),
      ),
    );
    expect(ignorePointer.ignoring, true);
  });

  testWidgets('tapping the close button un-minimizes', (tester) async {
    final c = await _pumpBar(tester, minimized: true);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(c.read(playerMinimizedProvider), false);
  });

  testWidgets('tapping the bar expands to PlayerScreen', (tester) async {
    await _pumpBar(tester, minimized: true);
    await tester.tap(find.text('ep1.mkv'));
    // Drive the push transition without pumpAndSettle: PlayerScreen keeps
    // scheduling frames (position/duration streams), which would make
    // pumpAndSettle time out — same pattern as player_screen_controls_test.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(PlayerScreen), findsOneWidget);
  });
}
