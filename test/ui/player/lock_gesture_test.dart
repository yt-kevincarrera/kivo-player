import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/platform/device_controls_provider.dart';
import 'package:kivo_player/platform/interfaces/device_controls.dart';
import 'package:kivo_player/ui/player/state/lock_state.dart';
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
}

void main() {
  testWidgets('when locked, a vertical drag does not change volume', (tester) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
      deviceControlsProvider.overrideWithValue(NoopControls()),
    ]);
    addTearDown(c.dispose);
    c.read(lockProvider.notifier).lock();

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: PlayerGestures(child: SizedBox.expand()))),
    ));

    await tester.drag(find.byType(PlayerGestures), const Offset(0, -200));
    await tester.pump();
    expect(engine.volume, 100); // unchanged default — locked ignored the drag
  });
}
