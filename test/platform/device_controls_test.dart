import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/interfaces/device_controls.dart';

class RecordingControls implements DeviceControls {
  double brightness = 0.5;
  @override
  Future<double> currentBrightness() async => brightness;
  @override
  Future<void> setBrightness(double v01) async => brightness = v01.clamp(0.0, 1.0);
  @override
  Future<double> currentVolume() async => 0.5;
  @override
  Future<void> setSystemVolume(double v01) async {}
  @override
  Future<void> setOrientation(List<DeviceOrientationLock> o) async {}
  @override
  Future<void> keepAwake(bool on) async {}
  @override
  Future<void> setImmersive(bool on) async {}
}

void main() {
  test('brightness clamps to 0..1', () async {
    final c = RecordingControls();
    await c.setBrightness(1.5);
    expect(await c.currentBrightness(), 1.0);
    await c.setBrightness(-0.2);
    expect(await c.currentBrightness(), 0.0);
  });
}
