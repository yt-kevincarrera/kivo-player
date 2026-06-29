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

  /// Sets the preferred device orientations.
  ///
  /// - An empty [orientations] list resets to Flutter's default (all
  ///   orientations allowed).
  /// - If [DeviceOrientationLock.auto] appears **anywhere** in the list, the
  ///   method returns immediately after calling
  ///   `setPreferredOrientations(DeviceOrientation.values)`, enabling all
  ///   orientations; any other entries in [orientations] are ignored.
  /// - Otherwise only the explicitly listed orientations are locked.
  @override
  Future<void> setOrientation(List<DeviceOrientationLock> orientations) {
    final mapped = <DeviceOrientation>[];
    for (final o in orientations) {
      switch (o) {
        case DeviceOrientationLock.auto:
          return SystemChrome.setPreferredOrientations(DeviceOrientation.values);
        case DeviceOrientationLock.portrait:
          mapped.addAll(
              [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
        case DeviceOrientationLock.landscape:
          mapped.addAll([
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
      }
    }
    return SystemChrome.setPreferredOrientations(mapped);
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
