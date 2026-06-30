import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/control/player_controller.dart';
import 'package:kivo_player/platform/device_controls_provider.dart';
import 'package:kivo_player/platform/interfaces/device_controls.dart';
import '../../fakes/fakes.dart';

class RecordingControls implements DeviceControls {
  double brightness = 0.5, volume = 0.5;
  @override Future<double> currentBrightness() async => brightness;
  @override Future<void> setBrightness(double v) async => brightness = v;
  @override Future<double> currentVolume() async => volume;
  @override Future<void> setSystemVolume(double v) async => volume = v;
  @override Future<void> setOrientation(List<DeviceOrientationLock> o) async {}
  @override Future<void> keepAwake(bool on) async {}
  @override Future<void> setImmersive(bool on) async {}
  @override Future<void> resetBrightness() async {}
  @override Stream<double> get systemVolumeStream => const Stream<double>.empty();
  @override Future<void> setVolumeKeyInterception(bool on) async {}
}

void main() {
  late FakePlaybackEngine engine;
  late RecordingControls controls;
  late ProviderContainer c;

  Future<void> setup() async {
    engine = FakePlaybackEngine();
    controls = RecordingControls();
    final settings = await SettingsService.load(InMemorySettingsStore());
    c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(settings),
      playbackEngineProvider.overrideWithValue(engine),
      deviceControlsProvider.overrideWithValue(controls),
    ]);
    addTearDown(engine.dispose);
    addTearDown(c.dispose);
    // activate position/duration providers
    c.listen(positionProvider, (_, __) {});
    c.listen(durationProvider, (_, __) {});
  }

  test('skipBy clamps using live position and duration', () async {
    await setup();
    engine.emitDuration(const Duration(minutes: 10));
    engine.emitPosition(const Duration(minutes: 1));
    await Future<void>.delayed(Duration.zero);
    c.read(playerControllerProvider).skipBy(10);
    expect(engine.lastSeek, const Duration(minutes: 1, seconds: 10));
  });

  test('setVolumePercent maps system + player gain and updates provider', () async {
    await setup();
    c.read(playerControllerProvider).setVolumePercent(140);
    await Future<void>.delayed(Duration.zero);
    expect(controls.volume, 1.0);          // system capped at 100%
    expect(engine.volume, 140);            // player amplified
    expect(c.read(volumePercentProvider), 140);
  });

  test('setVolumePercent stores user-facing value (not player gain) for sub-100 volume', () async {
    await setup();
    c.read(playerControllerProvider).setVolumePercent(50);
    await Future<void>.delayed(Duration.zero);
    expect(controls.volume, 0.5);          // system at 50% of max
    expect(engine.volume, 100);            // player gain unity (no attenuation)
    expect(c.read(volumePercentProvider), 50); // provider holds user-facing 50, NOT 100
  });

  test('setRate clamps to max and updates provider', () async {
    await setup();
    c.read(playerControllerProvider).setRate(9.0);
    await Future<void>.delayed(Duration.zero);
    expect(engine.rate, 4.0);
    expect(c.read(rateProvider), 4.0);
  });
}
