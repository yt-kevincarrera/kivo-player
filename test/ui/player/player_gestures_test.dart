import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/platform/device_controls_provider.dart';
import 'package:kivo_player/platform/interfaces/device_controls.dart';
import 'package:kivo_player/ui/player/state/controls_visibility.dart';
import 'package:kivo_player/ui/player/gestures/player_gestures.dart';
import '../../fakes/fakes.dart';

class NoopControls implements DeviceControls {
  @override Future<double> currentBrightness() async => 0.5;
  @override Future<void> setBrightness(double v) async {}
  @override Future<double> currentVolume() async => 0.5;
  @override Future<void> setSystemVolume(double v) async {}
  @override Future<void> setOrientation(List<DeviceOrientationLock> o) async {}
  @override Future<void> keepAwake(bool on) async {}
}

void main() {
  testWidgets('single tap toggles controls visibility', (tester) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
      deviceControlsProvider.overrideWithValue(NoopControls()),
    ]);
    addTearDown(c.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(
        home: Scaffold(body: PlayerGestures(child: SizedBox.expand())),
      ),
    ));

    expect(c.read(controlsVisibleProvider), false);
    await tester.tap(find.byType(PlayerGestures));
    // onTap fires after the double-tap timeout (~300ms) when onDoubleTap is also registered.
    await tester.pump(const Duration(milliseconds: 500));
    expect(c.read(controlsVisibleProvider), true);
    // Drain the auto-hide timer (controlsAutoHideMs = 3000ms default).
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('double tap on right edge skips forward', (tester) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
      deviceControlsProvider.overrideWithValue(NoopControls()),
    ]);
    addTearDown(c.dispose);

    // Seed position and duration via runAsync so stream events resolve in real async
    // context before pumpWidget hooks into fake_async.
    await tester.runAsync(() async {
      c.listen(positionProvider, (_, __) {});
      c.listen(durationProvider, (_, __) {});
      engine.emitDuration(const Duration(minutes: 10));
      engine.emitPosition(const Duration(minutes: 1));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: PlayerGestures(child: SizedBox.expand()))),
    ));
    await tester.pump(); // settle initial frame

    final box = tester.getRect(find.byType(PlayerGestures));
    final right = Offset(box.right - 40, box.center.dy);
    await tester.tapAt(right);
    await tester.pump(const Duration(milliseconds: 50)); // settle first tap
    await tester.tapAt(right); // second tap → double tap fires
    await tester.pump(const Duration(milliseconds: 50));
    expect(engine.lastSeek, const Duration(minutes: 1, seconds: 10));
    // Dispose container to cancel HUD/controls timers before framework cleanup.
    c.dispose();
    await tester.pump();
  });
}
