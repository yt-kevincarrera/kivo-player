import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../platform/device_controls_provider.dart';
import '../../../platform/interfaces/device_controls.dart';

DeviceOrientationLock nextOrientation(DeviceOrientationLock c) => switch (c) {
      DeviceOrientationLock.landscape => DeviceOrientationLock.portrait,
      DeviceOrientationLock.portrait => DeviceOrientationLock.auto,
      DeviceOrientationLock.auto => DeviceOrientationLock.landscape,
    };

class OrientationNotifier extends Notifier<DeviceOrientationLock> {
  @override
  DeviceOrientationLock build() => DeviceOrientationLock.landscape;

  void apply() => ref.read(deviceControlsProvider).setOrientation([state]);

  void cycle() {
    state = nextOrientation(state);
    apply();
  }
}

final orientationProvider =
    NotifierProvider<OrientationNotifier, DeviceOrientationLock>(OrientationNotifier.new);
