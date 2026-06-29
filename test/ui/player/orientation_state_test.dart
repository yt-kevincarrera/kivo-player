import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/platform/device_controls_provider.dart';
import 'package:kivo_player/platform/interfaces/device_controls.dart';
import 'package:kivo_player/ui/player/state/orientation_state.dart';

class RecCtrls implements DeviceControls {
  List<DeviceOrientationLock>? lastOrientation;
  @override Future<double> currentBrightness() async => 0.5;
  @override Future<void> setBrightness(double v) async {}
  @override Future<double> currentVolume() async => 0.5;
  @override Future<void> setSystemVolume(double v) async {}
  @override Future<void> setOrientation(List<DeviceOrientationLock> o) async => lastOrientation = o;
  @override Future<void> keepAwake(bool on) async {}
  @override Future<void> setImmersive(bool on) async {}
}

void main() {
  test('nextOrientation toggles portrait<->landscape (both auto and landscape go to portrait)', () {
    expect(nextOrientation(DeviceOrientationLock.landscape), DeviceOrientationLock.portrait);
    expect(nextOrientation(DeviceOrientationLock.portrait), DeviceOrientationLock.landscape);
    expect(nextOrientation(DeviceOrientationLock.auto), DeviceOrientationLock.portrait);
  });
  test('cycle() updates state and applies to device controls', () {
    final ctrls = RecCtrls();
    final c = ProviderContainer(overrides: [deviceControlsProvider.overrideWithValue(ctrls)]);
    addTearDown(c.dispose);
    expect(c.read(orientationProvider), DeviceOrientationLock.landscape);
    c.read(orientationProvider.notifier).cycle();
    expect(c.read(orientationProvider), DeviceOrientationLock.portrait);
    expect(ctrls.lastOrientation, [DeviceOrientationLock.portrait]);
  });
}
