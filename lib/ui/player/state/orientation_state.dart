import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../platform/device_controls_provider.dart';
import '../../../platform/interfaces/device_controls.dart';

DeviceOrientationLock nextOrientation(DeviceOrientationLock c) =>
    c == DeviceOrientationLock.portrait
        ? DeviceOrientationLock.landscape
        : DeviceOrientationLock.portrait;

class OrientationNotifier extends Notifier<DeviceOrientationLock> {
  @override
  DeviceOrientationLock build() => DeviceOrientationLock.portrait;

  void apply() => ref.read(deviceControlsProvider).setOrientation([state]);

  void cycle() {
    state = nextOrientation(state);
    apply();
  }

  /// Forces portrait, ignoring any manual rotation left over from a
  /// previous video. Call before [apply] on every fresh player entry so
  /// each video always opens in portrait by default (a future setting will
  /// make this configurable).
  void reset() => state = DeviceOrientationLock.portrait;
}

final orientationProvider =
    NotifierProvider<OrientationNotifier, DeviceOrientationLock>(OrientationNotifier.new);
