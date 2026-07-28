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
  @override Future<void> resetBrightness() async {}
  @override Stream<double> get systemVolumeStream => const Stream<double>.empty();
  @override Future<void> setVolumeKeyInterception(bool on) async {}
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
    expect(c.read(orientationProvider), DeviceOrientationLock.portrait);
    c.read(orientationProvider.notifier).cycle();
    expect(c.read(orientationProvider), DeviceOrientationLock.landscape);
    expect(ctrls.lastOrientation, [DeviceOrientationLock.landscape]);
  });

  test('swipeRotateTarget: portrait rotates on swipe UP, landscape on swipe DOWN', () {
    const p = DeviceOrientationLock.portrait;
    const l = DeviceOrientationLock.landscape;
    // Portrait: only an upward swipe (negative dy) past the threshold rotates.
    expect(swipeRotateTarget(p, -48), l);
    expect(swipeRotateTarget(p, -200), l);
    expect(swipeRotateTarget(p, -47), isNull); // too short
    expect(swipeRotateTarget(p, 200), isNull); // wrong direction (down)
    // Landscape: only a downward swipe (positive dy) past the threshold rotates.
    expect(swipeRotateTarget(l, 48), p);
    expect(swipeRotateTarget(l, 200), p);
    expect(swipeRotateTarget(l, 47), isNull);  // too short
    expect(swipeRotateTarget(l, -200), isNull); // wrong direction (up)
    // A stationary drag never rotates either way.
    expect(swipeRotateTarget(p, 0), isNull);
    expect(swipeRotateTarget(l, 0), isNull);
  });

  test('rotateTo() sets the given orientation and applies it', () {
    final ctrls = RecCtrls();
    final c = ProviderContainer(overrides: [deviceControlsProvider.overrideWithValue(ctrls)]);
    addTearDown(c.dispose);
    c.read(orientationProvider.notifier).rotateTo(DeviceOrientationLock.landscape);
    expect(c.read(orientationProvider), DeviceOrientationLock.landscape);
    expect(ctrls.lastOrientation, [DeviceOrientationLock.landscape]);
  });

  test('reset() forces portrait regardless of prior state', () {
    final ctrls = RecCtrls();
    final c = ProviderContainer(overrides: [deviceControlsProvider.overrideWithValue(ctrls)]);
    addTearDown(c.dispose);
    c.read(orientationProvider.notifier).cycle(); // now landscape
    expect(c.read(orientationProvider), DeviceOrientationLock.landscape);
    c.read(orientationProvider.notifier).reset();
    expect(c.read(orientationProvider), DeviceOrientationLock.portrait);
  });
}
