enum DeviceOrientationLock { auto, portrait, landscape }

abstract class DeviceControls {
  Future<void> setBrightness(double v01);
  Future<double> currentBrightness();
  Future<void> setSystemVolume(double v01);
  Future<double> currentVolume();
  Future<void> setOrientation(List<DeviceOrientationLock> orientations);
  Future<void> keepAwake(bool on);
  Future<void> setImmersive(bool on);
  Future<void> resetBrightness();
}
