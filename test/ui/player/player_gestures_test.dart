import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/control/player_controller.dart';
import 'package:kivo_player/platform/device_controls_provider.dart';
import 'package:kivo_player/platform/interfaces/device_controls.dart';
import 'package:kivo_player/ui/player/state/controls_visibility.dart';
import 'package:kivo_player/ui/player/state/orientation_state.dart';
import 'package:kivo_player/player/background/audio_only.dart';
import 'package:kivo_player/ui/player/gestures/player_gestures.dart';
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
    // No addTearDown(c.dispose) here: this test disposes c explicitly before the
    // final pump (to cancel timers), so a teardown dispose would double-dispose.

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

  Future<ProviderContainer> pumpGestures(WidgetTester tester,
      {bool audioOnly = false}) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
      deviceControlsProvider.overrideWithValue(NoopControls()),
    ]);
    addTearDown(c.dispose);
    if (audioOnly) c.read(audioOnlyProvider.notifier).toggle();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: PlayerGestures(child: SizedBox.expand()))),
    ));
    await tester.pump();
    return c;
  }

  testWidgets('swipe down from the top strip rotates (portrait→landscape)', (tester) async {
    final c = await pumpGestures(tester);
    expect(c.read(orientationProvider), DeviceOrientationLock.portrait);
    final box = tester.getRect(find.byType(PlayerGestures));
    await tester.dragFrom(Offset(box.center.dx, box.top + 6), const Offset(0, 140));
    await tester.pump(const Duration(milliseconds: 400)); // drain the double-tap countdown
    expect(c.read(orientationProvider), DeviceOrientationLock.landscape);
  });

  testWidgets('swipe down from the center does NOT rotate', (tester) async {
    final c = await pumpGestures(tester);
    final box = tester.getRect(find.byType(PlayerGestures));
    await tester.dragFrom(box.center, const Offset(0, 140));
    // Center drag adjusts brightness → shows the HUD (auto-hide timer); drain it
    // plus the double-tap countdown before teardown checks for pending timers.
    await tester.pump(const Duration(seconds: 4));
    expect(c.read(orientationProvider), DeviceOrientationLock.portrait);
  });

  testWidgets('in Solo audio, the top swipe does NOT rotate', (tester) async {
    final c = await pumpGestures(tester, audioOnly: true);
    final box = tester.getRect(find.byType(PlayerGestures));
    await tester.dragFrom(Offset(box.center.dx, box.top + 6), const Offset(0, 140));
    await tester.pump(const Duration(milliseconds: 400)); // drain the double-tap countdown
    expect(c.read(orientationProvider), DeviceOrientationLock.portrait);
  });

  testWidgets('releasing a hold-to-speed restores the selected rate, not 1x', (tester) async {
    final c = await pumpGestures(tester);
    c.read(rateProvider.notifier).state = 1.5; // user's selected speed
    final box = tester.getRect(find.byType(PlayerGestures));
    // Long-press on the left half → hold-left accelerates; release restores.
    await tester.longPressAt(Offset(box.left + box.width * 0.25, box.center.dy));
    await tester.pump(const Duration(milliseconds: 500)); // drain gesture timers
    expect(c.read(rateProvider), 1.5);
  });
}
