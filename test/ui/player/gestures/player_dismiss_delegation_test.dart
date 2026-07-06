import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/platform/device_controls_provider.dart';
import 'package:kivo_player/platform/interfaces/device_controls.dart';
import 'package:kivo_player/ui/player/gestures/player_gestures.dart';
import 'package:kivo_player/ui/player/state/player_dismiss_state.dart';
import '../../../fakes/fakes.dart';

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
  testWidgets('a committed dismiss drag calls PlayerDismissApi.complete', (tester) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final s = await SettingsService.load(InMemorySettingsStore());
    var completed = 0;
    var cancelled = 0;
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
      deviceControlsProvider.overrideWithValue(NoopControls()),
    ]);
    addTearDown(c.dispose);
    c.read(playerDismissProvider.notifier).state = PlayerDismissApi(
      complete: () => completed++,
      cancel: () => cancelled++,
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(
        home: Scaffold(body: PlayerGestures(child: SizedBox.expand())),
      ),
    ));

    // Drag from left strip downward well past the 25% threshold.
    final size = tester.getSize(find.byType(PlayerGestures));
    final start = Offset(20, size.height * 0.35);
    await tester.dragFrom(start, Offset(0, size.height * 0.5));
    await tester.pumpAndSettle();

    expect(completed, 1);
    expect(cancelled, 0);
  });

  testWidgets('a tiny dismiss drag calls cancel, not complete', (tester) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final s = await SettingsService.load(InMemorySettingsStore());
    var completed = 0;
    var cancelled = 0;
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
      deviceControlsProvider.overrideWithValue(NoopControls()),
    ]);
    addTearDown(c.dispose);
    c.read(playerDismissProvider.notifier).state = PlayerDismissApi(
      complete: () => completed++,
      cancel: () => cancelled++,
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(
        home: Scaffold(body: PlayerGestures(child: SizedBox.expand())),
      ),
    ));

    final size = tester.getSize(find.byType(PlayerGestures));
    final start = Offset(20, size.height * 0.5);
    await tester.dragFrom(start, const Offset(0, 20)); // small, slow
    await tester.pumpAndSettle();

    expect(completed, 0);
    expect(cancelled, 1);
  });
}
