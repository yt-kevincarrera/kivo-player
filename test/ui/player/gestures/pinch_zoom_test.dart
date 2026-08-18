import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/device_controls_provider.dart';
import 'package:kivo_player/platform/interfaces/device_controls.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/ui/player/gestures/player_gestures.dart';
import 'package:kivo_player/ui/player/state/zoom_state.dart';
import '../../../fakes/fakes.dart';

// Local, deliberately not imported from a sibling test file: one test file's
// internals should not become another's contract.
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

Future<ProviderContainer> _harness(WidgetTester tester) async {
  final engine = FakePlaybackEngine();
  addTearDown(engine.dispose);
  final s = await SettingsService.load(InMemorySettingsStore());
  final c = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(s),
    playbackEngineProvider.overrideWithValue(engine),
    deviceControlsProvider.overrideWithValue(_NoopControls()),
  ]);
  addTearDown(c.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: const MaterialApp(
      home: Scaffold(body: PlayerGestures(child: SizedBox.expand())),
    ),
  ));
  return c;
}

/// Drives a two-finger spread (or squeeze, with a negative [step]) about the
/// centre of the player.
Future<void> _pinch(WidgetTester tester, {double step = 16, int steps = 5}) async {
  final centre = tester.getCenter(find.byType(PlayerGestures));
  final a = await tester.startGesture(centre - const Offset(30, 0));
  final b = await tester.startGesture(centre + const Offset(30, 0));
  await tester.pump();
  for (var i = 0; i < steps; i++) {
    await a.moveBy(Offset(-step, 0));
    await b.moveBy(Offset(step, 0));
    await tester.pump();
  }
  await a.up();
  await b.up();
  await tester.pump();
  // Drain the double-tap recognizer's timers; they outlive the gesture and
  // would otherwise trip the "pending timers" check at teardown.
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('a two-finger spread zooms in', (tester) async {
    final c = await _harness(tester);
    await _pinch(tester);

    expect(c.read(zoomProvider).active, true);
    expect(c.read(zoomProvider).scale, greaterThan(1.5));
  });

  testWidgets('a squeeze back down settles at 1x', (tester) async {
    final c = await _harness(tester);
    await _pinch(tester);
    expect(c.read(zoomProvider).active, true);

    // Squeeze hard enough to bottom out against the 1x floor.
    final centre = tester.getCenter(find.byType(PlayerGestures));
    final a = await tester.startGesture(centre - const Offset(150, 0));
    final b = await tester.startGesture(centre + const Offset(150, 0));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await a.moveBy(const Offset(14, 0));
      await b.moveBy(const Offset(-14, 0));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(c.read(zoomProvider).active, false);
    expect(c.read(zoomProvider).offset, Offset.zero);
  });

  testWidgets('one finger pans while zoomed instead of changing volume',
      (tester) async {
    final c = await _harness(tester);
    final viewport = tester.getSize(find.byType(PlayerGestures));
    c.read(zoomProvider.notifier).pinch(
        factor: 2.0,
        focal: Offset(viewport.width / 2, viewport.height / 2),
        viewport: viewport);
    final before = c.read(zoomProvider).offset;

    // A drag on the RIGHT half, which at 1x would be the volume gesture.
    await tester.drag(
        find.byType(PlayerGestures), const Offset(0, -80),
        warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(c.read(zoomProvider).offset.dy, lessThan(before.dy),
        reason: 'the drag reframed the video');
    expect(c.read(zoomProvider).scale, 2.0, reason: 'panning must not change the scale');
  });

  testWidgets('the pinch is inert when the setting is off', (tester) async {
    final c = await _harness(tester);
    await c
        .read(settingsProvider.notifier)
        .set(c.read(settingsProvider).copyWith(pinchZoom: false));
    await tester.pump();

    await _pinch(tester);

    expect(c.read(zoomProvider).active, false);
  });

  testWidgets('a pinch in never mode persists the settled factor once',
      (tester) async {
    final c = await _harness(tester);
    await c.read(settingsProvider.notifier).set(
        c.read(settingsProvider).copyWith(zoomResetMode: 'never'));
    await tester.pump();

    await _pinch(tester);
    await tester.pump();

    expect(c.read(settingsProvider).zoomRemembered, c.read(zoomProvider).scale);
    expect(c.read(settingsProvider).zoomRemembered, greaterThan(1.0));
  });
}
