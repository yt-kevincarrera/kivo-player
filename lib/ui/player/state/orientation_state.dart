import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../platform/device_controls_provider.dart';
import '../../../platform/interfaces/device_controls.dart';

DeviceOrientationLock nextOrientation(DeviceOrientationLock c) =>
    c == DeviceOrientationLock.portrait
        ? DeviceOrientationLock.landscape
        : DeviceOrientationLock.portrait;

/// The orientation a center-band vertical swipe should land on, or null when the
/// swipe doesn't qualify (shorter than [threshold], or the wrong direction for
/// the current orientation). Portrait rotates on a swipe UP (negative [dy]),
/// landscape on a swipe DOWN — the gesture always points the way you want the
/// video to open, so it can never fire in the opposite direction.
DeviceOrientationLock? swipeRotateTarget(
  DeviceOrientationLock current,
  double dy, {
  double threshold = 48,
}) {
  if (current == DeviceOrientationLock.landscape) {
    return dy >= threshold ? DeviceOrientationLock.portrait : null;
  }
  return dy <= -threshold ? DeviceOrientationLock.landscape : null;
}

class OrientationNotifier extends Notifier<DeviceOrientationLock> {
  @override
  DeviceOrientationLock build() => DeviceOrientationLock.portrait;

  void apply() => ref.read(deviceControlsProvider).setOrientation([state]);

  void cycle() => rotateTo(nextOrientation(state));

  /// Sets an explicit orientation. The center-band swipe picks a direction
  /// rather than toggling (see [swipeRotateTarget]), so it needs this instead of
  /// [cycle] — a downward swipe in landscape must land on portrait, never flip
  /// back to landscape.
  void rotateTo(DeviceOrientationLock next) {
    state = next;
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
