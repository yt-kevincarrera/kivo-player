import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../interfaces/device_controls.dart';

class AndroidDeviceControls implements DeviceControls {
  AndroidDeviceControls() {
    // Suppress Android's native volume slider — Kivo shows its own HUD.
    VolumeController.instance.showSystemUI = false;
  }

  @override
  Future<void> setBrightness(double v01) =>
      ScreenBrightness().setApplicationScreenBrightness(v01.clamp(0.0, 1.0));

  @override
  Future<double> currentBrightness() => ScreenBrightness().application;

  @override
  Future<void> setSystemVolume(double v01) =>
      VolumeController.instance.setVolume(v01.clamp(0.0, 1.0));

  @override
  Future<double> currentVolume() => VolumeController.instance.getVolume();

  static const MethodChannel _orientationChannel =
      MethodChannel('kivo/orientation');

  /// Drives the native activity orientation. Uses SENSOR_LANDSCAPE/PORTRAIT so it
  /// overrides the system rotation lock (auto-rotate may be off) and still flips
  /// 180° between both sides; [DeviceOrientationLock.auto] returns to system default.
  /// Only [orientations].first is used (single coarse lock); pass a one-element
  /// list, or an empty list for auto.
  @override
  Future<void> setOrientation(List<DeviceOrientationLock> orientations) async {
    final o =
        orientations.isEmpty ? DeviceOrientationLock.auto : orientations.first;
    final mode = switch (o) {
      DeviceOrientationLock.landscape => 'sensorLandscape',
      DeviceOrientationLock.portrait => 'sensorPortrait',
      DeviceOrientationLock.auto => 'auto',
    };
    await _orientationChannel.invokeMethod('set', {'mode': mode});
  }

  @override
  Future<void> keepAwake(bool on) => WakelockPlus.toggle(enable: on);

  @override
  Future<void> setImmersive(bool on) async {
    await SystemChrome.setEnabledSystemUIMode(
      on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }
}

final deviceControls = AndroidDeviceControls();
