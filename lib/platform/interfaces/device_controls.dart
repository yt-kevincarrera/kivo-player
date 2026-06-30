import 'dart:async';

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

  /// Emits the system volume (0..1) on every change, including hardware keys.
  Stream<double> get systemVolumeStream;

  /// When [on], hardware volume keys are intercepted natively: the OS volume
  /// panel is suppressed and the volume change still flows through
  /// [systemVolumeStream], so only Kivo's HUD shows. Enable on player entry,
  /// disable on exit (the library keeps the normal OS volume panel).
  Future<void> setVolumeKeyInterception(bool on);
}
